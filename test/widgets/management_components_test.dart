import 'package:countdown_todo/widgets/management_page.dart';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('提取后卡片与原有结构像素一致', (tester) async {
    Future<Uint8List> render(Widget child, ColorScheme scheme) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Scaffold(
                body: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: 300, child: child))),
          )));
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return Uint8List.fromList(bytes!.buffer.asUint8List());
      }))!;
    }

    for (final brightness in Brightness.values) {
      final scheme =
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: brightness);
      const child = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('记录名称'),
            SizedBox(height: 12),
            Icon(Icons.inventory_2_outlined)
          ]);
      final before = await render(
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            color: scheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.5))),
            child: const Padding(padding: EdgeInsets.all(16), child: child),
          ),
          scheme);
      final after = await render(const ManagementCard(child: child), scheme);
      expect(listEquals(before, after), isTrue);
    }
  });
  testWidgets('搜索框独立更新清空入口，外部控制器仍由调用方持有', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ManagementSearchField(
      controller: controller,
      hintText: '搜索名称',
      onChanged: changes.add,
    ))));
    controller.text = '外部更新';
    await tester.pump();
    expect(find.byTooltip('清空搜索'), findsOneWidget);
    expect(changes, isEmpty);
    await tester.tap(find.byTooltip('清空搜索'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes, ['']);
    expect(find.byTooltip('清空搜索'), findsNothing);
    await tester.enterText(find.byType(TextField), '输入');
    expect(changes.last, '输入');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.text = '卸载后仍可使用';
  });

  testWidgets('筛选值由调用方控制且支持禁用', (tester) async {
    String selected = 'active';
    String? emitted;
    bool enabled = true;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return ManagementFilterBar<String>(
          value: selected,
          options: const [
            ManagementFilterOption(value: 'active', label: '使用中'),
            ManagementFilterOption(value: 'archived', label: '已归档'),
          ],
          onChanged: enabled ? (value) => emitted = value : null);
    }))));
    await tester.tap(find.text('已归档'));
    await tester.pump();
    expect(emitted, 'archived');
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('active')))
            .selected,
        isTrue);
    update(() => selected = emitted!);
    await tester.pump();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('archived')))
            .selected,
        isTrue);
    update(() => enabled = false);
    await tester.pump();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('active')))
            .onSelected,
        isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('公共卡片跟随动态主题 $brightness', (tester) async {
      final scheme = ColorScheme.fromSeed(
          seedColor: Colors.purple, brightness: brightness);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: const Scaffold(body: ManagementCard(child: Text('内容')))));
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, scheme.surfaceContainerLow);
      expect((card.shape! as RoundedRectangleBorder).side.color,
          scheme.outlineVariant.withValues(alpha: 0.5));
      expect(card.elevation, 0);
    });
  }

  testWidgets('重试提示仅在点击时回调，支持完整与内联状态', (tester) async {
    var retries = 0;
    for (final inline in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ManagementLoadError(
        title: '加载失败',
        description: '请稍后重试',
        inline: inline,
        onRetry: () => retries++,
      ))));
      final before = retries;
      await tester.pump();
      expect(retries, before);
      await tester.tap(find.text('重新加载'));
      expect(retries, before + 1);
    }
  });

  testWidgets('小屏大字体操作区自动换行且回调不变', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var invoked = 0;
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.8)),
              child: child!,
            ),
        home: Scaffold(
            body: ManagementPage(children: [
          ManagementCard(
              child: ManagementActionBar(children: [
            TextButton(onPressed: () => invoked++, child: const Text('查看历史详情')),
            FilledButton(
                onPressed: () => invoked++, child: const Text('恢复当前记录')),
          ])),
        ]))));
    expect(tester.getTopLeft(find.text('恢复当前记录')).dy,
        greaterThan(tester.getBottomLeft(find.text('查看历史详情')).dy));
    await tester.tap(find.text('恢复当前记录'));
    expect(invoked, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面页面限制宽度且保留滚动容器', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: ManagementPage(
                maxWidth: 900,
                children: [ManagementCard(child: Text('桌面内容'))]))));
    expect(tester.getSize(find.byType(ManagementCard)).width, 900);
    expect(find.byType(ListView), findsOneWidget);
  });
}
